// Shared steps for the Patrol web tests. Selectors are the Arabic UI texts
// (the app opens in Arabic whatever the browser locale is).
import 'dart:js_interop';

import 'package:al_mraay/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'emulator.dart';

const _long = Duration(seconds: 30);

/// From the root route (AdminAuthGuard): fill the login form and wait for the
/// admin dashboard.
Future<void> signInAsAdmin(PatrolIntegrationTester $) async {
  await $(TextFormField).first.waitUntilVisible(timeout: _long);
  // The form restores saved credentials right after it shows; let that land
  // first so it does not clear what we type.
  await $.pump(const Duration(seconds: 2));
  await typeInto($, $(TextFormField).at(0), adminEmail);
  await typeInto($, $(TextFormField).at(1), adminPassword);
  await $('دخول الحساب').tap();
  await waitOrDump($, $('الفواتير'));
}

@JS('window.history.replaceState')
external void _replaceState(JSAny? data, String title, String url);

/// Starts the app as if the browser opened [path] directly. The app reads
/// Uri.base at start (anonymous session for customer links, initial route),
/// so the address bar must change before main() runs.
Future<void> startAppAt(PatrolIntegrationTester $, String path) async {
  _replaceState(null, '', path);
  app.main();
  await $.pump(const Duration(seconds: 1));
}

/// Types [text] into a text field and checks it landed. In a release web
/// build the test text input sometimes drops the second field's text; then
/// the field's controller is set directly so the flow can go on.
Future<void> typeInto(PatrolIntegrationTester $, PatrolFinder field, String text) async {
  await field.enterText(text);
  final editable = $.tester.widget<EditableText>(find.descendant(of: field.finder, matching: find.byType(EditableText)));
  if (editable.controller.text != text) {
    editable.controller.text = text;
    await $.pump();
  }
}

/// Pushes a named route through the app's own onGenerateRoute.
Future<void> openRoute(PatrolIntegrationTester $, String route) async {
  final nav = $.tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.pushNamed(route);
  await $.pump(const Duration(milliseconds: 500));
}

/// On the upload screen: picks [bytes] through the gallery button and starts
/// the scan. The browser opens a file chooser only on a real user click, so
/// Playwright clicks the button through the semantics tree and answers the
/// chooser with [bytes].
Future<void> uploadReceipt(PatrolIntegrationTester $, List<int> bytes) async {
  const button = 'رفع من المعرض (الملفات)';
  await waitOrDump($, $(button));
  final semantics = $.tester.ensureSemantics();
  try {
    await $.pump(const Duration(milliseconds: 500));
    final chooser = $.platform.web.uploadFile(files: [
      UploadFileData(name: 'synthetic-receipt.jpg', content: bytes, mimeType: 'image/jpeg'),
    ]);
    await $.platform.web.tap(WebSelector(cssOrXpath: 'role=button[name="$button"]'));
    await chooser;
  } finally {
    semantics.dispose();
  }
  const scan = 'فحص الفاتورة بالذكاء الاصطناعي';
  await $(scan).waitUntilExists(timeout: _long);
  await $(scan).scrollTo().tap();
}

/// On the gift screen: picks the first gift and confirms, once per chance.
/// After each confirm the app shows a congratulations panel with "next gift"
/// while chances remain. Returns how many rounds were confirmed.
Future<int> pickGiftEachRound(PatrolIntegrationTester $) async {
  var rounds = 0;
  while (rounds < 10) {
    await waitOrDump($, $(GridView).$(InkWell));
    await $(GridView).$(InkWell).first.scrollTo().tap();
    await $(RegExp('^تأكيد الهدية')).scrollTo().tap();
    await waitOrDump($, $('تهانينا! ألف مبروك'));
    rounds++;
    final next = $(RegExp('^اختيار الهدية التالية'));
    if (!next.exists) break;
    // The dialog's buttons sit below the fold on a short browser window.
    await $.tester.ensureVisible(next.first);
    await $.pump(const Duration(milliseconds: 500));
    await next.tap();
    final end = DateTime.now().add(_long);
    while ($('تهانينا! ألف مبروك').exists && DateTime.now().isBefore(end)) {
      await $.pump(const Duration(milliseconds: 300));
    }
  }
  return rounds;
}

/// Waits for [finder]; on timeout fails with the texts on screen, which is
/// what you need to see when a step lands on an unexpected screen.
Future<void> waitOrDump(PatrolIntegrationTester $, PatrolFinder finder, {Duration timeout = _long}) async {
  try {
    await finder.waitUntilExists(timeout: timeout);
  } on Exception {
    throw StateError('Timed out waiting for $finder. On screen: ${screenTexts()}');
  }
}

/// The distinct texts on screen, for failure messages.
String screenTexts() => find
        .byWidgetPredicate((w) => w is Text || w is RichText)
        .evaluate()
        .map((e) => e.widget is Text ? (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() : (e.widget as RichText).text.toPlainText())
        .whereType<String>()
        .where((t) => t.trim().isNotEmpty)
        .toSet()
        .take(60)
        .join(' | ');

/// Runs [body] while ignoring the one expected image error: the synthetic
/// receipt bytes are text, not an image, so the preview cannot decode them.
/// Every other framework error still fails the test.
Future<T> allowSyntheticPreviewError<T>(Future<T> Function() body) async {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exception.toString();
    if (details.library == 'image resource service' && text.contains('Failed to detect image file format')) return;
    original?.call(details);
  };
  try {
    return await body();
  } finally {
    FlutterError.onError = original;
  }
}
