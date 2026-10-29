import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/constants/app_version_config.dart';
import 'package:al_mraay/core/update/app_update_checker.dart';

void main() {
  test('pubspec version matches AppVersionConfig (version.json source)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
    expect(m?.group(1), AppVersionConfig.semVer);
  });

  test('web/version.json matches AppVersionConfig', () {
    final j = jsonDecode(File('web/version.json').readAsStringSync()) as Map;
    final v = '${AppVersionConfig.major}.${AppVersionConfig.minor}.${AppVersionConfig.patch}';
    expect(j['version'], v);
    expect(j['build_number'], '${AppVersionConfig.buildNumber}');
  });

  test('isNewerBuild', () {
    expect(isNewerBuild('{"build_number":"179"}', 178), isTrue);
    expect(isNewerBuild('{"build_number":178}', 178), isFalse);
    expect(isNewerBuild('{"build_number":"111"}', 178), isFalse);
    expect(isNewerBuild('garbage', 178), isFalse);
    expect(isNewerBuild('{}', 178), isFalse);
  });

  test('never prompts on upload routes', () {
    for (final p in ['/c', '/c/', '/C', '/submit', '/client', '/promoter']) {
      expect(isUpdatePromptAllowedForPath(p), isFalse, reason: p);
    }
    for (final p in ['/', '/login', '/ops', '/campaign']) {
      expect(isUpdatePromptAllowedForPath(p), isTrue, reason: p);
    }
  });

  group('shouldPromptForUpdate', () {
    const run = BuildId(2, 0, 137, 192);
    test('same or older remote never prompts', () {
      expect(shouldPromptForUpdate(remote: run, running: run), isFalse);
      expect(shouldPromptForUpdate(remote: const BuildId(2, 0, 136, 191), running: run), isFalse);
      expect(shouldPromptForUpdate(remote: null, running: run), isFalse);
    });
    test('numeric, not string, comparison', () {
      expect(const BuildId(2, 0, 100, 200) > const BuildId(2, 0, 99, 199), isTrue);
      expect(const BuildId(2, 0, 9, 9) > const BuildId(2, 0, 10, 10), isFalse);
    });
    test('newer remote prompts once; dismissed version not re-shown', () {
      const r = BuildId(2, 0, 138, 193);
      expect(shouldPromptForUpdate(remote: r, running: run), isTrue);
      expect(shouldPromptForUpdate(remote: r, running: run, lastHandled: r), isFalse);
      expect(shouldPromptForUpdate(remote: const BuildId(2, 0, 139, 194), running: run, lastHandled: r), isTrue);
    });
    test('parsing', () {
      expect(BuildId.fromVersionJson('{"version":"2.0.137","build_number":"192"}'), run);
      expect(BuildId.tryParse('2.0.137+192'), run);
      expect(BuildId.fromVersionJson('garbage'), isNull);
    });
  });
}
