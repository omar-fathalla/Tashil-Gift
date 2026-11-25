import 'package:al_mraay/core/config/app_env.dart';
import 'package:al_mraay/core/config/firebase_env_options.dart';
import 'package:al_mraay/core/constants/app_version_config.dart';
import 'package:al_mraay/core/utils/url_builder.dart';
import 'package:al_mraay/firebase_options.dart';
import 'package:al_mraay/firebase_options_dev.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('APP_ENV (TAG-8)', () {
    test('a build without --dart-define is production, as before', () {
      // flutter test runs without APP_ENV, exactly like the prod build.
      expect(kAppEnvRaw, '');
      expect(kIsDevEnv, isFalse);
      expect(AppEnv.current, AppEnvironment.prod);
      expect(AppEnv.label, 'prod');
      expect(kDefaultHostingOrigin, 'https://tashil-gift.web.app');
      expect(AppUrlBuilder.productionDomain, 'https://tashil-gift.web.app');
      expect(AppVersionConfig.environment, 'Production (Firebase)');
      expect(AppVersionConfig.envLabel, 'prod');
    });

    test('parse accepts only known values', () {
      expect(parseAppEnvironment(''), AppEnvironment.prod);
      expect(parseAppEnvironment('prod'), AppEnvironment.prod);
      expect(parseAppEnvironment('production'), AppEnvironment.prod);
      expect(parseAppEnvironment('dev'), AppEnvironment.dev);
      expect(parseAppEnvironment('development'), AppEnvironment.dev);
      expect(() => parseAppEnvironment('dve'), throwsArgumentError);
      expect(() => parseAppEnvironment('DEV'), throwsArgumentError);
    });

    test('prod options are the unchanged tashil-gift options', () {
      final o = firebaseOptionsFor(AppEnvironment.prod);
      expect(o, same(DefaultFirebaseOptions.currentPlatform));
      expect(o.projectId, 'tashil-gift');
    });

    test('dev never falls back to production', () {
      // Placeholders still in place -> refuse.
      if (!DevFirebaseOptions.isConfigured) {
        expect(
          () => firebaseOptionsFor(AppEnvironment.dev, isWeb: true),
          throwsA(isA<DevFirebaseConfigMissing>()),
        );
      }
      expect(
        () => firebaseOptionsFor(AppEnvironment.dev, isWeb: false),
        throwsUnsupportedError,
      );
      const filled = FirebaseOptions(
        apiKey: 'k',
        appId: '1:2:web:3',
        messagingSenderId: '2',
        projectId: 'tashil-gift-dev',
        authDomain: 'tashil-gift-dev.firebaseapp.com',
        storageBucket: 'tashil-gift-dev.firebasestorage.app',
      );
      final o = firebaseOptionsFor(AppEnvironment.dev, isWeb: true, devWebOptions: filled);
      expect(o.projectId, 'tashil-gift-dev');
      const wrong = FirebaseOptions(
        apiKey: 'k',
        appId: '1:2:web:3',
        messagingSenderId: '2',
        projectId: 'tashil-gift',
        authDomain: 'tashil-gift.firebaseapp.com',
        storageBucket: 'tashil-gift.firebasestorage.app',
      );
      expect(
        () => firebaseOptionsFor(AppEnvironment.dev, isWeb: true, devWebOptions: wrong),
        throwsStateError,
      );
    });

    test('dev options file only targets tashil-gift-dev', () {
      expect(DevFirebaseOptions.web.projectId, 'tashil-gift-dev');
      expect(DevFirebaseOptions.web.storageBucket, isNot(contains('tashil-gift.')));
      expect(DevFirebaseOptions.web.authDomain, isNot(startsWith('tashil-gift.')));
    });

    test('labels and origins per environment', () {
      expect(AppEnv.labelOf(AppEnvironment.dev), 'dev');
      expect(AppEnv.projectIdOf(AppEnvironment.dev), 'tashil-gift-dev');
      expect(AppEnv.hostingOriginOf(AppEnvironment.dev), 'https://tashil-gift-dev.web.app');
      expect(AppEnv.hostingOriginOf(AppEnvironment.prod), 'https://tashil-gift.web.app');
    });
  });
}
