import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TAG-10: the four AI services (ai_receipt_service, campaign_ai_assistant_service,
/// branch_signature_ai_service, ai_product_catalog_service) once carried a
/// hard-coded Google API key (removed in v2.0.6). Gemini now goes through the
/// geminiGenerate Cloud Function, which reads GEMINI_API_KEY from Secret
/// Manager per project. This guard keeps it that way: the only Google API key
/// allowed in lib/ is the public Firebase web config in firebase_options*.dart.
void main() {
  final keyPattern = RegExp(r'AIza[0-9A-Za-z_\-]{30,}');
  const allowed = {'lib/firebase_options.dart', 'lib/firebase_options_dev.dart'};

  test('no Google API key outside the Firebase options files', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      if (allowed.contains(path)) continue;
      if (keyPattern.hasMatch(f.readAsStringSync())) offenders.add(path);
    }
    expect(offenders, isEmpty, reason: 'Move keys to Secret Manager (functions) instead.');
  });

  test('the four AI services call Gemini through the Cloud Function', () {
    for (final name in const [
      'ai_receipt_service.dart',
      'campaign_ai_assistant_service.dart',
      'branch_signature_ai_service.dart',
      'ai_product_catalog_service.dart',
    ]) {
      final src = File('lib/core/services/$name').readAsStringSync();
      expect(src, contains('CloudGenerativeModel'), reason: name);
      expect(src, isNot(contains('generativelanguage.googleapis.com')), reason: name);
      expect(src, isNot(contains('apiKey:')), reason: name);
    }
  });
}
