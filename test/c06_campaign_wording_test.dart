// C-06: user-facing wording on the campaign page. Fails if a forbidden word
// comes back into a string literal of the page (or its C-05 dialogs), or into
// an Arabic value of app_strings.dart.
import 'dart:io';

import 'package:al_mraay/features/admin/domain/campaign_wording.dart';
import 'package:flutter_test/flutter_test.dart';

const _pageFiles = [
  'lib/features/admin/presentation/create_event_screen.dart',
  'lib/features/admin/presentation/widgets/campaign_activation_summary_dialog.dart',
  'lib/features/admin/presentation/widgets/campaign_try_receipt_dialog.dart',
  'lib/features/admin/presentation/widgets/campaign_drafts_sheet.dart',
  'lib/features/admin/domain/campaign_activation_review.dart',
];

/// Word → why it is not allowed on screen.
final _forbidden = <RegExp, String>{
  RegExp('بروموتر'): 'use «مندوب»',
  RegExp('نشر'): 'activating a campaign is «تفعيل الحملة»',
  RegExp('فايربيس|Firebase|Firestore', caseSensitive: false): 'technical name',
  RegExp('برومبت|Prompt', caseSensitive: false): 'use «تعليمات قراءة الفواتير»',
  RegExp(r'الـ AI|\bAI\b'): 'use «الذكاء الاصطناعي»',
  RegExp(r'\b(merge|brand|tier|dropdown|gemini|gpt|claude|openai)\b', caseSensitive: false): 'raw English / model name',
  RegExp('باسورد'): 'use «كلمة مرور»',
  RegExp('بونات|البون'): 'use «فاتورة»',
  RegExp('فواتشر|فوتشر|فاوتشر'): 'use «كارت مشتريات» (stored names go through CampaignWording.giftLabel)',
  RegExp('[\u0660-\u0669]'): 'Western digits only',
};

final _literal = RegExp(r"'((?:[^'\\]|\\.)*)'|" r'"((?:[^"\\]|\\.)*)"');
final _arabic = RegExp('[\u0600-\u06FF]');

/// Arabic string literals per line, without `${...}` / `$name` interpolation.
Iterable<(int, String, String)> _arabicLiterals(String path) sync* {
  final lines = File(path).readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('//')) continue;
    for (final m in _literal.allMatches(line)) {
      final s = m.group(1) ?? m.group(2) ?? '';
      if (!_arabic.hasMatch(s)) continue;
      yield (i + 1, line, s.replaceAll(RegExp(r'\$\{[^}]*\}|\$[A-Za-z_]\w*'), ''));
    }
  }
}

/// Literals that are compared or stored, not shown as is.
bool _allowed(String line, String text) {
  if (line.contains('C-06: stored value')) return true;
  // Voucher detection on stored names / rule values.
  if (RegExp(r'\.(contains|startsWith)\(').hasMatch(line) && RegExp('^(فواتشر|فوتشر)\$').hasMatch(text)) return true;
  // Product names as printed on receipts (sample rules, search aliases).
  if (RegExp(r'\\b\(|Toothpaste|tresemme|sunsilk|Signal|Closeup').hasMatch(line)) {
    return !RegExp('بروموتر|نشر|فايربيس|برومبت|فواتشر').hasMatch(text);
  }
  return false;
}

void main() {
  test('the campaign page shows no forbidden words', () {
    final problems = <String>[];
    for (final path in _pageFiles) {
      for (final (lineNo, line, text) in _arabicLiterals(path)) {
        if (_allowed(line, text)) continue;
        _forbidden.forEach((re, why) {
          if (re.hasMatch(text)) problems.add('$path:$lineNo «${re.firstMatch(text)![0]}» ($why): $text');
        });
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('Arabic app strings never say «بروموتر» or «البرومبت»', () {
    final src = File('lib/core/localization/app_strings.dart').readAsStringSync();
    final bad = RegExp(r"ar:\s*'((?:[^'\\]|\\.)*)'")
        .allMatches(src)
        .map((m) => m.group(1)!)
        .where((s) => s.contains('بروموتر') || s.contains('البرومبت'))
        .toList();
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('the guard catches the old wording', () {
    for (final old in ['رابط البروموتر الميداني', 'تم نشر وتفعيل الحملة على الفايربيس!', 'تخصيص الـ AI', 'كارت فواتشر مشتريات']) {
      expect(_forbidden.keys.any((re) => re.hasMatch(old)), isTrue, reason: old);
    }
  });

  test('gift label: display only, stored name unchanged', () {
    expect(CampaignWording.giftLabel('كارت فواتشر مشتريات'), 'كارت مشتريات');
    expect(CampaignWording.giftLabel('فواتشر 50 جنيه'), 'كارت مشتريات 50 جنيه');
    expect(CampaignWording.giftLabel('فوتشر 25'), 'كارت مشتريات 25');
    expect(CampaignWording.giftLabel('شنطة كادبري'), 'شنطة كادبري');
    expect(CampaignWording.giftLabel(''), '');
  });
}
