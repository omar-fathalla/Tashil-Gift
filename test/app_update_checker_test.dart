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
}
